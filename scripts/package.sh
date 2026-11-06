#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${VERSION:-0.3.0}"
DIST="${DIST:-$ROOT/dist}"
APP="$DIST/FanLite.app"
ZIP="$DIST/FanLite-v${VERSION}-macos-arm64.zip"
DMG="$DIST/FanLite-v${VERSION}-macos-arm64.dmg"

VERSION="$VERSION" DIST="$DIST" "$ROOT/scripts/build.sh"

rm -f "$ZIP" "$ZIP.sha256"
ditto -c -k --norsrc --keepParent "$APP" "$ZIP"
(cd "$DIST" && shasum -a 256 "$(basename "$ZIP")" | tee "$(basename "$ZIP").sha256")
echo "package: $ZIP"

# Drag-to-Applications DMG
STAGE="$DIST/dmg-stage"
rm -rf "$STAGE"
mkdir -p "$STAGE"
ditto "$APP" "$STAGE/FanLite.app"
ln -s /Applications "$STAGE/Applications"
rm -f "$DMG" "$DMG.sha256"
hdiutil create -quiet -volname "FanLite" -srcfolder "$STAGE" -ov -format UDZO "$DMG"
(cd "$DIST" && shasum -a 256 "$(basename "$DMG")" | tee "$(basename "$DMG").sha256")
echo "package: $DMG"
