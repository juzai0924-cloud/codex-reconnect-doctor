#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
BUILD="$ROOT/build"
APP="$BUILD/Codex Reconnect Doctor.app"
CONTENTS="$APP/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"
HELPERS="$CONTENTS/Helpers"
SDK="/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk"
MODULE_CACHE="$BUILD/ModuleCache"

mkdir -p "$MACOS" "$RESOURCES" "$HELPERS" "$MODULE_CACHE"

swiftc \
  -swift-version 5 \
  -O \
  -target arm64-apple-macosx13.0 \
  -sdk "$SDK" \
  -module-cache-path "$MODULE_CACHE" \
  -framework AppKit \
  -framework Foundation \
  "$ROOT"/Sources/*.swift \
  -o "$MACOS/CodexReconnectDoctor"

swiftc \
  -swift-version 5 \
  -O \
  -target arm64-apple-macosx13.0 \
  -sdk "$SDK" \
  -module-cache-path "$MODULE_CACHE" \
  -framework Foundation \
  "$ROOT/Helper/ProxyEnvironmentHelper.swift" \
  -o "$HELPERS/CodexProxyEnvironmentHelper"

cp "$ROOT/Resources/Info.plist" "$CONTENTS/Info.plist"
cp "$ROOT/Resources/AppIcon.icns" "$RESOURCES/AppIcon.icns"
chmod +x "$MACOS/CodexReconnectDoctor" "$HELPERS/CodexProxyEnvironmentHelper"
codesign --force --deep --sign - "$APP" >/dev/null

echo "$APP"
