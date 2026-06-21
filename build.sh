#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP="$ROOT/build/Squishy.app"
CONTENTS="$APP/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"
MODULE_CACHE="$ROOT/build/ModuleCache"
ICONSET="$ROOT/build/Squishy.iconset"

rm -rf "$ROOT/build"
mkdir -p "$MACOS" "$RESOURCES" "$MODULE_CACHE"

xcrun swiftc \
  -swift-version 5 \
  -parse-as-library \
  -target arm64-apple-macosx13.0 \
  -sdk "$(xcrun --sdk macosx --show-sdk-path)" \
  -module-cache-path "$MODULE_CACHE" \
  -framework AppKit \
  "$ROOT/Sources/IconGenerator/IconGenerator.swift" \
  -o "$ROOT/build/IconGenerator"

"$ROOT/build/IconGenerator" "$ICONSET"
iconutil -c icns "$ICONSET" -o "$RESOURCES/Squishy.icns"

xcrun swiftc \
  -swift-version 5 \
  -parse-as-library \
  -target arm64-apple-macosx13.0 \
  -sdk "$(xcrun --sdk macosx --show-sdk-path)" \
  -module-cache-path "$MODULE_CACHE" \
  -framework SwiftUI \
  -framework AppKit \
  -framework UniformTypeIdentifiers \
  "$ROOT/Sources/Squishy/main.swift" \
  -o "$MACOS/Squishy"

cp "$ROOT/Info.plist" "$CONTENTS/Info.plist"
rm -rf "$MODULE_CACHE" "$ICONSET" "$ROOT/build/IconGenerator"

echo "$APP"
