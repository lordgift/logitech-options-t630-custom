#!/bin/zsh
# Build LogiSwipe.app and install it to /Applications.
#   SIGN_IDENTITY  code signing identity; default "LogiSwipe Self-Signed" if it is in the keychain,
#                  else "-" (ad hoc). With ad hoc signing macOS asks for Accessibility / Input
#                  Monitoring again after every rebuild.
set -euo pipefail
cd "${0:A:h}"

swift build -c release
app=build/LogiSwipe.app
rm -rf $app
mkdir -p $app/Contents/MacOS $app/Contents/Resources
cp .build/release/LogiSwipe $app/Contents/MacOS/
cp Support/Info.plist $app/Contents/
cp Support/AppIcon.icns $app/Contents/Resources/
# Sign with the "LogiSwipe Self-Signed" identity when it is in the keychain, so macOS keeps the
# Accessibility / Input Monitoring permissions across builds; otherwise ad hoc. SIGN_IDENTITY overrides.
identities=$(security find-identity -p codesigning 2>/dev/null || true)
[[ $identities == *'"LogiSwipe Self-Signed"'* ]] && identity="LogiSwipe Self-Signed" || identity=-
identity=${SIGN_IDENTITY:-$identity}
codesign --force --sign "$identity" $app

pkill -x LogiSwipe || true
rm -rf /Applications/LogiSwipe.app
cp -R $app /Applications/
echo "Installed /Applications/LogiSwipe.app"
