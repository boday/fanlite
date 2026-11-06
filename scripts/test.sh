#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/dist/FanLite.app"

VERSION=0.4.0 DIST="$ROOT/dist" "$ROOT/scripts/build.sh" >/dev/null
out="$("$APP/Contents/MacOS/FanLite" --once)"
echo "$out"
"$APP/Contents/MacOS/FanLite" --policy-test

[[ "$out" == *"cpu_max="*"C fans="*"RPM package="*"W" ]] || {
  echo "unexpected output" >&2
  exit 1
}
echo "PASS: sensor read and CLI output"

login_status="$("$APP/Contents/MacOS/FanLite" --login-item-status)"
echo "$login_status"
[[ "$login_status" == enabled* || "$login_status" == disabled* ]] || {
  echo "unexpected login item status" >&2
  exit 1
}
echo "PASS: login item status"
