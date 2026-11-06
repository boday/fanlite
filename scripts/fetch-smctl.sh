#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="0.2.4"
SHA256="a9bac1c53b12ffb0c29765a9e34644bcb536f76bf046e0d7ae1dae7133420b36"
URL="https://github.com/leaperone/smctl/releases/download/v${VERSION}/smctl-${VERSION}-arm64.zip"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$ROOT/bin"
if [[ -x "$ROOT/bin/smctl" ]]; then
  echo "smctl already present: $ROOT/bin/smctl"
  exit 0
fi

echo "downloading smctl v${VERSION}…"
curl -fL --retry 3 -A FanLite -o "$TMP/smctl.zip" "$URL"
echo "${SHA256}  $TMP/smctl.zip" | shasum -a 256 -c -
unzip -q "$TMP/smctl.zip" -d "$TMP/out"
cp "$TMP/out/smctl-${VERSION}-arm64/smctl" "$ROOT/bin/smctl"
cp "$TMP/out/smctl-${VERSION}-arm64/smctld" "$ROOT/bin/smctld"
cp "$TMP/out/smctl-${VERSION}-arm64/LICENSE" "$ROOT/bin/LICENSE"
chmod +x "$ROOT/bin/smctl" "$ROOT/bin/smctld"
echo "installed: $ROOT/bin/smctl"
