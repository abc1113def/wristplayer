#!/usr/bin/env bash
# Ставит XcodeGen, если его нет (используется в CI). Печатает путь к папке с бинарником.
set -euo pipefail
if command -v xcodegen >/dev/null; then
  dirname "$(command -v xcodegen)"
  exit 0
fi
curl -sSL -o /tmp/xcodegen.zip https://github.com/yonaskolb/XcodeGen/releases/download/2.46.0/xcodegen.zip
rm -rf /tmp/xcodegen && unzip -q /tmp/xcodegen.zip -d /tmp/xcodegen
BIN="$(find /tmp/xcodegen -type f -name xcodegen | head -1)"
chmod +x "$BIN"
dirname "$BIN"
