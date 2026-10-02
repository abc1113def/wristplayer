#!/usr/bin/env bash
# Подписывает и загружает сборку в TestFlight (App Store Connect).
# Нужны переменные окружения (GitHub Secrets):
#   ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_P8_BASE64 — ключ App Store Connect API (роль Admin)
#   TEAM_ID                                       — Team ID из developer.apple.com → Membership
#   APP_BUNDLE_ID (необязательно)                 — свой bundle id, по умолчанию из project.yml
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
mkdir -p build

for var in ASC_KEY_ID ASC_ISSUER_ID ASC_KEY_P8_BASE64 TEAM_ID; do
  if [[ -z "${!var:-}" ]]; then
    echo "::error::Не задан секрет $var — см. docs/INSTALL.md"
    exit 1
  fi
done

export PATH="$(bash scripts/install_xcodegen.sh):$PATH"
xcodegen generate

KEY_PATH="${RUNNER_TEMP:-/tmp}/AuthKey_${ASC_KEY_ID}.p8"
echo "$ASC_KEY_P8_BASE64" | base64 --decode > "$KEY_PATH"
AUTH=(-allowProvisioningUpdates
      -authenticationKeyPath "$KEY_PATH"
      -authenticationKeyID "$ASC_KEY_ID"
      -authenticationKeyIssuerID "$ASC_ISSUER_ID")

BUILD_NUMBER="${BUILD_NUMBER:-${GITHUB_RUN_NUMBER:-1}}"
EXTRA=(DEVELOPMENT_TEAM="$TEAM_ID" CODE_SIGN_STYLE=Automatic CURRENT_PROJECT_VERSION="$BUILD_NUMBER")
if [[ -n "${APP_BUNDLE_ID:-}" ]]; then
  EXTRA+=(APP_BUNDLE_ID="$APP_BUNDLE_ID")
fi

xcodebuild archive \
  -project WristPlayer.xcodeproj -scheme WristPlayer -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath build/WristPlayer.xcarchive \
  "${AUTH[@]}" "${EXTRA[@]}"

cat > build/ExportOptions.plist <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>app-store-connect</string>
  <key>destination</key><string>upload</string>
  <key>teamID</key><string>${TEAM_ID}</string>
  <key>signingStyle</key><string>automatic</string>
  <key>manageAppVersionAndBuildNumber</key><false/>
</dict>
</plist>
PLIST

xcodebuild -exportArchive \
  -archivePath build/WristPlayer.xcarchive \
  -exportOptionsPlist build/ExportOptions.plist \
  -exportPath build/export \
  "${AUTH[@]}"

rm -f "$KEY_PATH"
echo "Сборка $BUILD_NUMBER загружена в App Store Connect. Через 5–20 минут она появится в TestFlight."
