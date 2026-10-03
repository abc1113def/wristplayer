#!/usr/bin/env bash
# Сквозной тест в CI: пара симуляторов iPhone + Watch, iPhone сам добавляет три песни
# и отправляет их на часы через WatchConnectivity. Подключается из scripts/ci.sh (source),
# использует его переменные: IPHONE, WATCH, IOS_APP, WATCH_APP, APP_ID, WATCH_ID, OUT.

set +e
group "Сквозной тест: iPhone → Watch"
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
PAIR="$(xcrun simctl pair "$E2E_WATCH" "$E2E_PHONE")"
echo "pair=$PAIR"
xcrun simctl boot "$E2E_PHONE" 2>/dev/null
xcrun simctl boot "$E2E_WATCH" 2>/dev/null
xcrun simctl bootstatus "$E2E_PHONE" -b
xcrun simctl bootstatus "$E2E_WATCH" -b
xcrun simctl pair_activate "$PAIR"
xcrun simctl list pairs

xcrun simctl uninstall "$E2E_PHONE" "$APP_ID" 2>/dev/null
xcrun simctl uninstall "$E2E_WATCH" "$WATCH_ID" 2>/dev/null
# Как при запуске из Xcode: сначала приложение на часы, затем на iPhone.
xcrun simctl install "$E2E_WATCH" "$WATCH_APP"
xcrun simctl install "$E2E_PHONE" "$IOS_APP"
WATCH_DATA="$(xcrun simctl get_app_container "$E2E_WATCH" "$WATCH_ID" data)"

wait_for_songs() {
  local i
  for i in $(seq 1 "$1"); do
    sleep 10
    COUNT="$(ls "$WATCH_DATA/Documents/Songs" 2>/dev/null | wc -l | tr -d ' ')"
    echo "t=$((i * 10))s: песен на часах: $COUNT"
    [[ "$COUNT" -ge 3 ]] && return 0
  done
  return 1
}

COUNT=0
# Первый запуск iPhone-приложения: оно добавляет три тестовые песни в библиотеку.
xcrun simctl launch "$E2E_PHONE" "$APP_ID" -e2eSeed
sleep 15
# WatchConnectivity в симуляторе замечает установленное приложение на часах только после перезагрузки пары.
xcrun simctl shutdown "$E2E_WATCH"
xcrun simctl shutdown "$E2E_PHONE"
xcrun simctl boot "$E2E_PHONE"
xcrun simctl boot "$E2E_WATCH"
xcrun simctl bootstatus "$E2E_PHONE" -b
xcrun simctl bootstatus "$E2E_WATCH" -b
sleep 15
xcrun simctl launch "$E2E_WATCH" "$WATCH_ID"
sleep 10
xcrun simctl launch "$E2E_PHONE" "$APP_ID"
wait_for_songs 42

ls -la "$WATCH_DATA/Documents/Songs" 2>&1
head -c 2000 "$WATCH_DATA/Documents/library.json" 2>&1
echo
xcrun simctl io "$E2E_PHONE" screenshot "$OUT/screenshots/e2e-iphone.png"
xcrun simctl io "$E2E_WATCH" screenshot "$OUT/screenshots/e2e-watch.png"
xcrun simctl spawn "$E2E_PHONE" log show --last 10m --style compact \
  --predicate 'subsystem == "com.apple.wcd" OR process == "WristPlayer"' \
  > "$OUT/logs/e2e-phone.log" 2>&1
xcrun simctl spawn "$E2E_WATCH" log show --last 10m --style compact \
  --predicate 'subsystem == "com.apple.wcd" OR process CONTAINS "WristPlayer"' \
  > "$OUT/logs/e2e-watch.log" 2>&1
grep -ho "appInstalled: [A-Z]*" "$OUT/logs/e2e-phone.log" | sort | uniq -c
echo "E2E_RESULT=$COUNT" | tee "$OUT/e2e-result.txt"
endgroup
set -e
if [[ "${COUNT:-0}" -lt 3 ]]; then
  echo "::warning::Сквозной тест: на часы пришло $COUNT из 3 песен"
fi
