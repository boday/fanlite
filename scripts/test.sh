#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/dist/FanLite.app"

VERSION="$(cat "$ROOT/VERSION")" DIST="$ROOT/dist" "$ROOT/scripts/build.sh" >/dev/null
out="$("$APP/Contents/MacOS/FanLite" --once)"
echo "$out"
"$APP/Contents/MacOS/FanLite" --policy-test

[[ "$out" == *"cpu_max="*"C fans="*"RPM package="*"W"* ]] || {
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

python3 "$ROOT/scripts/check_version.py"
echo "PASS: version single-source guard"

sensors="$("$APP/Contents/MacOS/FanLite" --sensors)"
sensor_count="$(printf '%s\n' "$sensors" | wc -l | tr -d ' ')"
[[ "$sensor_count" -ge 1 ]] || {
  echo "no sensors reported" >&2
  exit 1
}
echo "PASS: sensor enumeration ($sensor_count sensors)"

curve_status="$("$APP/Contents/MacOS/FanLite" --curve-status)"
[[ "$curve_status" == default* || "$curve_status" == custom* ]] || {
  echo "unexpected curve status" >&2
  exit 1
}
echo "PASS: curve status ($curve_status)"
