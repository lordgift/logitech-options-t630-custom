#!/bin/zsh
# Build LogiSwipe.app and install it to /Applications.
#   SIGN_IDENTITY  code signing identity; default "-" (ad hoc). With ad hoc signing macOS asks
#                  for Accessibility / Input Monitoring again after every rebuild.
set -euo pipefail
cd "${0:A:h}"

swift build -c release
app=build/LogiSwipe.app
rm -rf $app
mkdir -p $app/Contents/MacOS $app/Contents/Resources
cp .build/release/LogiSwipe $app/Contents/MacOS/
cp Support/Info.plist $app/Contents/
cp Support/AppIcon.icns $app/Contents/Resources/
codesign --force --sign "${SIGN_IDENTITY:--}" $app

pkill -x LogiSwipe || true
rm -rf /Applications/LogiSwipe.app
cp -R $app /Applications/
echo "Installed /Applications/LogiSwipe.app"
