#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP="$ROOT/build/Squishy.app"
CONTENTS="$APP/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"
MODULE_CACHE="$ROOT/build/ModuleCache"
ICON_BUILD="$ROOT/build/Icon"

rm -rf "$ROOT/build"
mkdir -p "$MACOS" "$RESOURCES" "$MODULE_CACHE" "$ICON_BUILD"

xcrun actool \
  --output-format human-readable-text \
  --compile "$ICON_BUILD" \
  --platform macosx \
  --minimum-deployment-target 14.0 \
  --app-icon squishy-icon \
  --output-partial-info-plist "$ICON_BUILD/partial.plist" \
  "$ROOT/public/squishy-icon.icon" > /dev/null

cp "$ICON_BUILD/squishy-icon.icns" "$RESOURCES/Squishy.icns"

xcrun swiftc \
  -swift-version 5 \
  -parse-as-library \
  -target arm64-apple-macosx14.0 \
  -sdk "$(xcrun --sdk macosx --show-sdk-path)" \
  -module-cache-path "$MODULE_CACHE" \
  -framework SwiftUI \
  -framework AppKit \
  -framework UniformTypeIdentifiers \
  "$ROOT/Sources/Squishy/main.swift" \
  -o "$MACOS/Squishy"

cp "$ROOT/Info.plist" "$CONTENTS/Info.plist"
rm -rf "$MODULE_CACHE" "$ICON_BUILD"

echo "$APP"
