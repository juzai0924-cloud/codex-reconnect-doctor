#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
APP="$ROOT/build/Codex Reconnect Doctor.app"
BINARY="$APP/Contents/MacOS/CodexReconnectDoctor"

"$ROOT/scripts/build.sh"
"$BINARY" --self-test
plutil -lint "$APP/Contents/Info.plist"
codesign --verify --deep --strict "$APP"

if rg -n '/bin/sh|ProgramArguments.*-c' "$ROOT/Sources" "$ROOT/Helper"; then
  echo "Unsafe shell-based runtime configuration found" >&2
  exit 1
fi

"$ROOT/scripts/package.sh"
unzip -tq "$ROOT/build/Codex-Reconnect-Doctor-arm64.zip"
echo "PASS: build, signature and package verification"
