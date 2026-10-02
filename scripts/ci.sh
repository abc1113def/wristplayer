#!/usr/bin/env bash
# CI: генерирует Xcode-проект, собирает iOS + watchOS приложения для симулятора,
# запускает unit-тесты и (по желанию) делает скриншоты демо-режима.
#
# Переменные окружения:
#   SCREENSHOTS=true   — снять скриншоты в симуляторах
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
DERIVED="$ROOT/build/DerivedData"
OUT="$ROOT/build/out"
APP_ID="io.github.abc1113def.wristplayer"
WATCH_ID="$APP_ID.watchkitapp"
mkdir -p "$OUT/screenshots" "$OUT/logs"

group() { echo "::group::$1"; }
endgroup() { echo "::endgroup::"; }

xcb() {
  local name="$1"; shift
  set -o pipefail
  if command -v xcbeautify >/dev/null; then
    xcodebuild "$@" 2>&1 | tee "$OUT/logs/$name.log" | xcbeautify --renderer github-actions
  else
    xcodebuild "$@" 2>&1 | tee "$OUT/logs/$name.log"
  fi
}

# Первый доступный симулятор, имя которого начинается с $1.
simulator() {
  xcrun simctl list devices available -j | python3 -c '
import json, sys
prefix = sys.argv[1]
devices = json.load(sys.stdin)["devices"]
for runtime in sorted(devices, reverse=True):
    for d in devices[runtime]:
        if d["name"].startswith(prefix):
            print(d["udid"]); sys.exit(0)
sys.exit(1)' "$1"
}

group "Окружение"
xcodebuild -version
sw_vers
endgroup

group "XcodeGen"
if ! command -v xcodegen >/dev/null; then
  curl -sSL -o /tmp/xcodegen.zip https://github.com/yonaskolb/XcodeGen/releases/download/2.46.0/xcodegen.zip
  rm -rf /tmp/xcodegen && unzip -q /tmp/xcodegen.zip -d /tmp/xcodegen
  XCODEGEN_BIN="$(find /tmp/xcodegen -type f -name xcodegen | head -1)"
  chmod +x "$XCODEGEN_BIN"
  export PATH="$(dirname "$XCODEGEN_BIN"):$PATH"
fi
xcodegen --version
xcodegen generate
(cd "$ROOT" && zip -qr "$OUT/WristPlayer.xcodeproj.zip" WristPlayer.xcodeproj)
endgroup

group "Сборка iPhone + Watch (симулятор)"
xcb build-ios build \
  -project WristPlayer.xcodeproj -scheme WristPlayer -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath "$DERIVED" \
  CODE_SIGNING_ALLOWED=NO
IOS_APP="$DERIVED/Build/Products/Debug-iphonesimulator/WristPlayer.app"
WATCH_APP="$DERIVED/Build/Products/Debug-watchsimulator/WristPlayerWatch.app"
test -d "$IOS_APP" || { echo "::error::нет $IOS_APP"; exit 1; }
test -d "$WATCH_APP" || { echo "::error::нет $WATCH_APP"; exit 1; }
test -d "$IOS_APP/Watch/WristPlayerWatch.app" || { echo "::error::watch-приложение не встроено в iOS-приложение"; exit 1; }
plutil -p "$WATCH_APP/Info.plist" | grep -E "WKApplication|WKCompanionAppBundleIdentifier|UIBackgroundModes" -A2 || true
endgroup

IPHONE="$(simulator 'iPhone 17' || simulator 'iPhone')"
echo "iPhone simulator: $IPHONE"

group "Unit-тесты"
xcb test test \
  -project WristPlayer.xcodeproj -scheme WristPlayer -configuration Debug \
  -destination "id=$IPHONE" \
  -derivedDataPath "$DERIVED" \
  -resultBundlePath "$OUT/tests.xcresult" \
  CODE_SIGNING_ALLOWED=NO
endgroup

if [[ "${SCREENSHOTS:-false}" == "true" ]]; then
  set +e
  group "Скриншоты iPhone"
  xcrun simctl boot "$IPHONE" 2>/dev/null
  xcrun simctl bootstatus "$IPHONE" -b
  xcrun simctl status_bar "$IPHONE" override --time "9:41" --batteryState charged --batteryLevel 100 --cellularBars 4 --wifiBars 3
  xcrun simctl install "$IPHONE" "$IOS_APP"
  xcrun simctl launch "$IPHONE" "$APP_ID" -demo
  sleep 8
  xcrun simctl io "$IPHONE" screenshot "$OUT/screenshots/iphone-library.png"
  xcrun simctl terminate "$IPHONE" "$APP_ID"
  xcrun simctl ui "$IPHONE" appearance dark
  xcrun simctl launch "$IPHONE" "$APP_ID" -demo
  sleep 6
  xcrun simctl io "$IPHONE" screenshot "$OUT/screenshots/iphone-library-dark.png"
  endgroup

  group "Скриншоты Watch"
  WATCH="$(simulator 'Apple Watch Series 11 (46mm)' || simulator 'Apple Watch')"
  echo "Watch simulator: $WATCH"
  xcrun simctl boot "$WATCH" 2>/dev/null
  xcrun simctl bootstatus "$WATCH" -b
  xcrun simctl install "$WATCH" "$WATCH_APP"
  for screen in library nowPlaying settings; do
    xcrun simctl terminate "$WATCH" "$WATCH_ID" 2>/dev/null
    xcrun simctl launch "$WATCH" "$WATCH_ID" -demo -demoScreen "$screen"
    sleep 8
    xcrun simctl io "$WATCH" screenshot "$OUT/screenshots/watch-$screen.png"
  done
  xcrun simctl spawn "$WATCH" log show --last 3m --predicate 'process == "WristPlayerWatch"' --style compact \
    > "$OUT/logs/watch-app.log" 2>&1
  endgroup
  set -e
fi

echo "Готово."
