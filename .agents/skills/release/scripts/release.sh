#!/bin/zsh
# Build LogiSwipe.app and compress it into build/LogiSwipe-<VERSION>.zip for release.
# Usage: ./release.sh <VERSION> [BUILD_NUMBER]
set -euo pipefail

VERSION="${1:?Usage: $0 <VERSION> [BUILD_NUMBER]}"
BUILD_NUM="${2:-1}"

ROOT_DIR="$(cd "${0:A:h}/../../../.." && pwd)"
cd "$ROOT_DIR"

PLIST="Support/Info.plist"

# Update CFBundleShortVersionString and CFBundleVersion in Info.plist
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUM" "$PLIST"

CURRENT_BUILD=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$PLIST")
echo "==> Version set to $VERSION (build $CURRENT_BUILD)"

echo "==> Building release binary..."
swift build -c release

APP="build/LogiSwipe.app"
ZIP="build/LogiSwipe-${VERSION}.zip"

rm -rf "$APP" "$ZIP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/LogiSwipe "$APP/Contents/MacOS/"
cp "$PLIST" "$APP/Contents/"

echo "==> Signing $APP..."
codesign --force --sign "${SIGN_IDENTITY:--}" "$APP"

echo "==> Compressing to $ZIP..."
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"

ls -lh "$ZIP"
echo "==> Release archive ready: $ZIP"
