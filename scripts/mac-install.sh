#!/usr/bin/env bash
# Установка WristPlayer на iPhone и Apple Watch с Mac (бесплатный Apple ID подходит).
#
# Что нужно заранее:
#   1. macOS 15.6+ и Xcode 26+ (на iMac 2013 — macOS Sequoia через OpenCore Legacy Patcher и Xcode 26.3, см. docs/MAC_SETUP.md).
#   2. В Xcode → Settings → Accounts добавлен ваш Apple ID.
#   3. iPhone подключён кабелем, разблокирован, нажато «Доверять»; на iPhone включён Режим разработчика.
#
# Запуск (в папке проекта):
#   bash scripts/mac-install.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

say() { printf '\n\033[1m%s\033[0m\n' "$1"; }

if ! xcodebuild -version >/dev/null 2>&1; then
  echo "Не найден Xcode. Установите Xcode 26+ и откройте его один раз."
  exit 1
fi
XCODE_MAJOR="$(xcodebuild -version | head -1 | awk '{print $2}' | cut -d. -f1)"
if (( XCODE_MAJOR < 26 )); then
  echo "Нужен Xcode 26 или новее (сейчас: $(xcodebuild -version | head -1))."
  exit 1
fi

say "1/4 Настройки подписи"
echo "Team ID: Xcode → Settings → Accounts → ваш Apple ID → в списке команд «(Personal Team)»."
echo "Его же видно в Xcode, если открыть проект и выбрать Team — 10 символов, например A1B2C3D4E5."
read -r -p "Team ID: " TEAM_ID
DEFAULT_ID="com.$(id -un | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9').wristplayer"
read -r -p "Bundle ID [$DEFAULT_ID]: " BUNDLE_ID
BUNDLE_ID="${BUNDLE_ID:-$DEFAULT_ID}"

sed -i '' -E "s/^( *APP_BUNDLE_ID:).*/\1 $BUNDLE_ID/; s/^( *DEVELOPMENT_TEAM:).*/\1 \"$TEAM_ID\"/" project.yml

say "2/4 Генерация проекта Xcode"
export PATH="$(bash scripts/install_xcodegen.sh):$PATH"
xcodegen generate

say "3/4 Поиск iPhone"
DEVICES_JSON="$(mktemp)"
xcrun devicectl list devices --json-output "$DEVICES_JSON" >/dev/null 2>&1 || true
IPHONE_ID="$(python3 - "$DEVICES_JSON" <<'PY'
import json, sys
try:
    devices = json.load(open(sys.argv[1]))["result"]["devices"]
except Exception:
    devices = []
for d in devices:
    props = d.get("hardwareProperties", {})
    if props.get("platform") == "iOS" and props.get("deviceType") == "iPhone":
        print(props.get("udid") or d.get("identifier")); break
PY
)"
if [[ -z "$IPHONE_ID" ]]; then
  echo "iPhone не найден. Подключите его кабелем, разблокируйте и нажмите «Доверять», затем запустите скрипт снова."
  exit 1
fi
echo "iPhone: $IPHONE_ID"

say "4/4 Сборка, подпись и установка"
if xcodebuild build \
     -project WristPlayer.xcodeproj -scheme WristPlayer -configuration Release \
     -destination "id=$IPHONE_ID" -derivedDataPath build/device \
     -allowProvisioningUpdates -allowProvisioningDeviceRegistration \
     DEVELOPMENT_TEAM="$TEAM_ID" | tail -5 \
   && xcrun devicectl device install app --device "$IPHONE_ID" \
     build/device/Build/Products/Release-iphoneos/WristPlayer.app; then
  say "Готово!"
  echo "На iPhone: Настройки → Основные → VPN и управление устройством → ваш Apple ID → «Доверять»."
  echo "Приложение для часов: приложение Watch на iPhone → Мои часы → WristPlayer → «Установить»."
  echo "Бесплатная подпись действует 7 дней — потом просто запустите этот скрипт ещё раз."
else
  say "Автоматически не получилось — доделаем в Xcode"
  echo "Сейчас откроется проект. Вверху выберите схему WristPlayer и ваш iPhone, нажмите ▶︎ (Run)."
  echo "Если Xcode попросит — разрешите регистрацию устройства и выберите Team в Signing & Capabilities"
  echo "для обеих целей: WristPlayer и WristPlayerWatch."
  open WristPlayer.xcodeproj
fi
