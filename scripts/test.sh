#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/dist/FanLite.app"

VERSION=0.2.0 DIST="$ROOT/dist" "$ROOT/scripts/build.sh" >/dev/null
out="$("$APP/Contents/MacOS/FanLite" --once)"
echo "$out"

[[ "$out" == *"cpu_max="*"C fans="*"RPM package="*"W" ]] || {
  echo "unexpected output" >&2
  exit 1
}
echo "PASS: sensor read and CLI output"
