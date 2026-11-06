#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${VERSION:-0.1.0}"
DIST="${DIST:-$ROOT/dist}"
APP="$DIST/FanLite.app"
ZIP="$DIST/FanLite-v${VERSION}-macos-arm64.zip"

VERSION="$VERSION" DIST="$DIST" "$ROOT/scripts/build.sh"

rm -f "$ZIP" "$ZIP.sha256"
ditto -c -k --norsrc --keepParent "$APP" "$ZIP"
(cd "$DIST" && shasum -a 256 "$(basename "$ZIP")" | tee "$(basename "$ZIP").sha256")
echo "package: $ZIP"
