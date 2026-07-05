#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
BUILD="$ROOT/build"
APP="$BUILD/Codex Reconnect Doctor.app"
CONTENTS="$APP/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"
SDK="/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk"
MODULE_CACHE="$BUILD/ModuleCache"

mkdir -p "$MACOS" "$RESOURCES" "$MODULE_CACHE"

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

cp "$ROOT/Resources/Info.plist" "$CONTENTS/Info.plist"
chmod +x "$MACOS/CodexReconnectDoctor"
codesign --force --deep --sign - "$APP" >/dev/null

echo "$APP"
