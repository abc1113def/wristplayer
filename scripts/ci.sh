#!/usr/bin/env bash
# CI: генерирует Xcode-проект, собирает iOS + watchOS приложения для симулятора,
# запускает unit-тесты и (по желанию) делает скриншоты демо-режима.
#
# Переменные окружения:
#   SCREENSHOTS=true   — снять скриншоты в симуляторах
#   E2E=true           — сквозной тест: пара симуляторов iPhone + Watch, передача песен через WatchConnectivity
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
export PATH="$(bash scripts/install_xcodegen.sh):$PATH"
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
  # Самый маленький экран — проверить, что всё помещается.
  SMALL="$(simulator 'Apple Watch SE 3 (40mm)' || simulator 'Apple Watch Series 11 (42mm)')"
  if [[ -n "$SMALL" ]]; then
    xcrun simctl boot "$SMALL" 2>/dev/null
    xcrun simctl bootstatus "$SMALL" -b
    xcrun simctl install "$SMALL" "$WATCH_APP"
    for screen in library nowPlaying; do
      xcrun simctl terminate "$SMALL" "$WATCH_ID" 2>/dev/null
      xcrun simctl launch "$SMALL" "$WATCH_ID" -demo -demoScreen "$screen"
      sleep 8
      xcrun simctl io "$SMALL" screenshot "$OUT/screenshots/watch-small-$screen.png"
    done
    xcrun simctl shutdown "$SMALL"
  fi
  endgroup
  set -e
fi

if [[ "${E2E:-false}" == "true" ]]; then
  set +e
  group "Сквозной тест: iPhone → Watch"
  # Берём уже загруженные симуляторы (первая загрузка нового симулятора занимает до 15 минут).
  E2E_PHONE="$IPHONE"
  E2E_WATCH="${WATCH:-$(simulator 'Apple Watch Series 11 (46mm)' || simulator 'Apple Watch')}"
  echo "phone=$E2E_PHONE watch=$E2E_WATCH"
  # Снимаем существующие пары с этими устройствами и создаём свою.
  xcrun simctl list pairs -j | python3 -c '
import json, sys
phone, watch = sys.argv[1], sys.argv[2]
for pid, p in json.load(sys.stdin)["pairs"].items():
    if p["watch"]["udid"] in (phone, watch) or p["phone"]["udid"] in (phone, watch):
        print(pid)' "$E2E_PHONE" "$E2E_WATCH" | while read -r old; do xcrun simctl unpair "$old"; done
  xcrun simctl uninstall "$E2E_PHONE" "$APP_ID" 2>/dev/null
  xcrun simctl boot "$E2E_WATCH" 2>/dev/null
  xcrun simctl uninstall "$E2E_WATCH" "$WATCH_ID" 2>/dev/null
  PAIR="$(xcrun simctl pair "$E2E_WATCH" "$E2E_PHONE")"
  echo "pair=$PAIR"
  xcrun simctl boot "$E2E_PHONE" 2>/dev/null
  xcrun simctl bootstatus "$E2E_PHONE" -b; xcrun simctl bootstatus "$E2E_WATCH" -b
  xcrun simctl pair_activate "$PAIR"
  # Сначала iPhone-приложение (как при установке из App Store), затем — часы.
  xcrun simctl install "$E2E_PHONE" "$IOS_APP"
  sleep 20
  if xcrun simctl listapps "$E2E_WATCH" | grep -q "$WATCH_ID"; then
    echo "watch-приложение установлено через iPhone"
  else
    echo "watch-приложение ставлю напрямую"
    xcrun simctl install "$E2E_WATCH" "$WATCH_APP"
  fi
  # Перезагрузка пары, чтобы WatchConnectivity увидел установленные приложения.
  xcrun simctl shutdown "$E2E_WATCH"; xcrun simctl shutdown "$E2E_PHONE"
  xcrun simctl boot "$E2E_PHONE"; xcrun simctl boot "$E2E_WATCH"
  xcrun simctl bootstatus "$E2E_PHONE" -b; xcrun simctl bootstatus "$E2E_WATCH" -b
  xcrun simctl list pairs
  xcrun simctl launch "$E2E_WATCH" "$WATCH_ID"
  sleep 10
  xcrun simctl launch "$E2E_PHONE" "$APP_ID" -e2eSeed
  WATCH_DATA="$(xcrun simctl get_app_container "$E2E_WATCH" "$WATCH_ID" data)"
  COUNT=0
  for i in $(seq 1 18); do
    sleep 10
    COUNT="$(ls "$WATCH_DATA/Documents/Songs" 2>/dev/null | wc -l | tr -d ' ')"
    echo "t=$((i * 10))s: песен на часах: $COUNT"
    [[ "$COUNT" -ge 3 ]] && break
  done
  ls -la "$WATCH_DATA/Documents/Songs" 2>&1
  head -c 2000 "$WATCH_DATA/Documents/library.json" 2>&1; echo
  # Перезапуск часов — проверить, что библиотека сохраняется.
  xcrun simctl terminate "$E2E_WATCH" "$WATCH_ID"
  xcrun simctl launch "$E2E_WATCH" "$WATCH_ID"
  sleep 6
  xcrun simctl io "$E2E_PHONE" screenshot "$OUT/screenshots/e2e-iphone.png"
  xcrun simctl io "$E2E_WATCH" screenshot "$OUT/screenshots/e2e-watch.png"
  xcrun simctl spawn "$E2E_PHONE" log show --last 5m --style compact \
    --predicate 'process == "WristPlayer" AND (subsystem == "com.apple.wcd" OR eventMessage CONTAINS "WristPlayer")' \
    > "$OUT/logs/e2e-phone.log" 2>&1
  xcrun simctl spawn "$E2E_WATCH" log show --last 5m --style compact \
    --predicate 'process CONTAINS "WristPlayer"' \
    > "$OUT/logs/e2e-watch.log" 2>&1
  echo "E2E_RESULT=$COUNT" | tee "$OUT/e2e-result.txt"
  endgroup
  set -e
  if [[ "${COUNT:-0}" -lt 3 ]]; then
    echo "::warning::Сквозной тест: на часы пришло $COUNT из 3 песен"
  fi
fi

echo "Готово."
