#!/bin/sh
# Builds an unsigned macOS release and wraps it in a DMG: build/Fluo.dmg
# Unsigned: on first open, right-click the app and choose Open (Gatekeeper).
set -eu
cd "$(dirname "$0")/.."
flutter build macos --release
APP="build/macos/Build/Products/Release/Fluo.app"
STAGE="$(mktemp -d)"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
rm -f build/Fluo.dmg
hdiutil create -volname Fluo -srcfolder "$STAGE" -ov -format UDZO build/Fluo.dmg
rm -rf "$STAGE"
echo "Built build/Fluo.dmg"
