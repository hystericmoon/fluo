#!/bin/bash
# Builds the macOS release and wraps it in a DMG: build/Fluo.dmg
#
# Without DEVELOPER_ID the app keeps Flutter's ad-hoc signature (unsigned for
# Gatekeeper): on first open, right-click the app and choose Open.
#
# With DEVELOPER_ID the app is signed with the hardened runtime, the DMG is
# signed, notarised by Apple and stapled, so it opens on any Mac without a
# warning. One-time setup is in docs/release.md ("macOS signing").
#
#   DEVELOPER_ID   signing identity, e.g. "Developer ID Application: Your Name (TEAMID)"
#   NOTARY_PROFILE keychain profile made with `xcrun notarytool store-credentials`
#                  (needed to notarise; without it the build is signed only)
set -euo pipefail
cd "$(dirname "$0")/.."

DEVELOPER_ID="${DEVELOPER_ID:-}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"
ENTITLEMENTS="macos/Runner/Release.entitlements"
APP="build/macos/Build/Products/Release/Fluo.app"
DMG="build/Fluo.dmg"

flutter build macos --release

if [ -n "$DEVELOPER_ID" ]; then
  security find-identity -v -p codesigning | grep -F "$DEVELOPER_ID" >/dev/null || {
    echo "No signing identity matches: $DEVELOPER_ID" >&2
    echo "List them with: security find-identity -v -p codesigning" >&2
    exit 1
  }

  # Sign inside-out: every nested binary first (deepest path first), then the
  # app itself. Not --deep: Apple discourages it and it can miss helpers.
  # --options runtime is the hardened runtime that notarisation requires;
  # --timestamp is a secure timestamp, also required.
  find "$APP/Contents" \
    \( -name '*.dylib' -o -name '*.framework' -o -name '*.xpc' -o -name '*.app' \) \
    -not -path "$APP" -print0 \
    | xargs -0 -n1 | awk '{ print length($0) " " $0 }' | sort -rn | cut -d' ' -f2- \
    | while IFS= read -r item; do
        codesign --force --timestamp --options runtime --sign "$DEVELOPER_ID" "$item"
      done
  # The app keeps its sandbox entitlements (the sandbox is on in Release).
  codesign --force --timestamp --options runtime \
    --entitlements "$ENTITLEMENTS" --sign "$DEVELOPER_ID" "$APP"

  codesign --verify --deep --strict --verbose=2 "$APP"
fi

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
rm -f "$DMG"
hdiutil create -volname Fluo -srcfolder "$STAGE" -ov -format UDZO "$DMG"

if [ -n "$DEVELOPER_ID" ]; then
  codesign --force --timestamp --sign "$DEVELOPER_ID" "$DMG"
  if [ -n "$NOTARY_PROFILE" ]; then
    # --wait blocks until Apple answers (usually a few minutes). On
    # "Invalid", read the log: xcrun notarytool log <submission-id> --keychain-profile ...
    xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$DMG"
    xcrun stapler validate "$DMG"
    spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG"
    echo "Built, signed, notarised and stapled: $DMG"
  else
    echo "Built and signed (not notarised, set NOTARY_PROFILE to notarise): $DMG"
  fi
else
  echo "Built unsigned (set DEVELOPER_ID to sign): $DMG"
fi
