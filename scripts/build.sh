#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${VERSION:-0.1.1}"
DIST="${DIST:-$ROOT/dist}"
APP="$DIST/FanLite.app"

if [[ ! -x "$ROOT/bin/smctl" || ! -x "$ROOT/bin/smctld" ]]; then
  "$ROOT/scripts/fetch-smctl.sh"
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/bin"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>FanLite</string>
    <key>CFBundleIdentifier</key><string>io.github.boday.fanlite</string>
    <key>CFBundleName</key><string>FanLite</string>
    <key>CFBundleDisplayName</key><string>FanLite</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>${VERSION}</string>
    <key>CFBundleVersion</key><string>${VERSION}</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSAppSleepDisabled</key><true/>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

swiftc -O -swift-version 5 -framework AppKit \
  "$ROOT/Sources/main.swift" \
  -o "$APP/Contents/MacOS/FanLite"

cp "$ROOT/bin/smctl" "$APP/Contents/Resources/bin/smctl"
cp "$ROOT/bin/smctld" "$APP/Contents/Resources/bin/smctld"
cp "$ROOT/bin/LICENSE" "$APP/Contents/Resources/bin/LICENSE"
chmod +x "$APP/Contents/Resources/bin/smctl" "$APP/Contents/Resources/bin/smctld"
codesign --force --deep --sign - "$APP" >/dev/null

if [[ "${1:-}" == "--install" ]]; then
  mkdir -p "$HOME/Applications"
  rm -rf "$HOME/Applications/FanLite.app"
  cp -R "$APP" "$HOME/Applications/FanLite.app"
  echo "installed: $HOME/Applications/FanLite.app"
fi

echo "built: $APP"
