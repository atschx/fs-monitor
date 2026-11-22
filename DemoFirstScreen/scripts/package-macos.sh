#!/bin/sh
# Run on the target Mac only after build-macos.sh (or it will build release itself).
# Creates DemoFirstScreen.app in ./dist. Does not notarize, push, or touch the original FSMonitor app.
set -eu
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"

if [ "$(uname -s)" != "Darwin" ]; then
  echo "package-macos.sh must run on macOS. This host is $(uname -s)." >&2
  exit 2
fi
if [ "$(uname -m)" != "arm64" ]; then
  echo "This checkpoint expects Apple Silicon (arm64)." >&2
  exit 2
fi

export MACOSX_DEPLOYMENT_TARGET=13.0
cd "$ROOT"
swift build -c release --arch arm64 -Xswiftc -target -Xswiftc arm64-apple-macos13.0

# New SwiftPM/Xcode may put products under .build/release or .build/out/Products/Release.
resolve_bin() {
  for d in     "$ROOT/.build/release"     "$ROOT/.build/out/Products/Release"     "$ROOT/.build/arm64-apple-macosx/release"
  do
    if [ -x "$d/DemoFirstScreen" ]; then
      printf "%s\n" "$d"
      return 0
    fi
  done
  return 1
}
BUILD_DIR="$(resolve_bin || true)"
BIN="${BUILD_DIR:-}/DemoFirstScreen"
if [ ! -x "$BIN" ]; then
  echo "expected executable not found under .build release products" >&2
  exit 1
fi

DIST="$ROOT/dist"
APP="$DIST/DemoFirstScreen.app"
CONTENTS="$APP/Contents"
MACOS="$CONTENTS/MacOS"
RES="$CONTENTS/Resources"
rm -rf "$APP"
mkdir -p "$MACOS" "$RES"

cp "$BIN" "$MACOS/DemoFirstScreen"
# Production resource bundles must travel with the executable for Bundle.module.
# Copy next to the executable and into Resources. Test bundles are not selected.
copy_bundle() {
  marker="$1"
  shift
  found=""
  for candidate in "$@"; do
    if [ -d "$candidate" ]; then
      found="$candidate"
      break
    fi
  done
  if [ -z "$found" ]; then
    echo "production resource bundle not found for marker $marker in $BUILD_DIR" >&2
    ls -la "$BUILD_DIR" >&2 || true
    exit 1
  fi
  cp -R "$found" "$MACOS/"
  cp -R "$found" "$RES/"
  if ! find "$MACOS" "$RES" -name "$marker" | grep -q .; then
    echo "missing $marker from packaged app" >&2
    exit 1
  fi
}
copy_bundle "eric-du-20261121-readonly.json" \
  "$BUILD_DIR/DemoFirstScreen_DemoFirstScreenCore.bundle" \
  "$BUILD_DIR/DemoFirstScreenCore.bundle"
copy_bundle "d2-hub.png" \
  "$BUILD_DIR/DemoFirstScreen_DemoFirstScreenCore.bundle" \
  "$BUILD_DIR/DemoFirstScreenCore.bundle"
copy_bundle "d2-eyes-rest.png" \
  "$BUILD_DIR/DemoFirstScreen_DemoFirstScreenCore.bundle" \
  "$BUILD_DIR/DemoFirstScreenCore.bundle"
copy_bundle "Eyes.metal" \
  "$BUILD_DIR/DemoFirstScreen_DemoFirstScreenApp.bundle" \
  "$BUILD_DIR/DemoFirstScreenApp.bundle"

cat > "$CONTENTS/Info.plist" << "PLIST"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>DemoFirstScreen</string>
  <key>CFBundleIdentifier</key>
  <string>me.atschx.fsmonitor.demofirstscreen</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>DemoFirstScreen</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.0-demo</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>CFBundleSupportedPlatforms</key>
  <array>
    <string>MacOSX</string>
  </array>
</dict>
</plist>
PLIST

chmod 0755 "$MACOS/DemoFirstScreen"
# Adhoc-sign nested bundles first, then the app. Do not swallow codesign errors.
# (--deep is avoided; inside-out signing is the supported order.)
if ! command -v codesign >/dev/null 2>&1; then
  echo "codesign not found" >&2
  exit 1
fi
find "$APP" -name "*.bundle" -type d -print | while IFS= read -r bundle; do
  codesign --force --sign - --timestamp=none "$bundle"
done
codesign --force --sign - --timestamp=none --identifier me.atschx.fsmonitor.demofirstscreen "$APP"
codesign --verify --strict --verbose=2 "$APP"

echo "APP=$APP"
ZIP="$DIST/DemoFirstScreen.app.zip"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
echo "ZIP=$ZIP"
echo "ZIP_SHA256=$(shasum -a 256 "$ZIP" | awk '{print $1}')"
echo "package-macos.sh finished."
