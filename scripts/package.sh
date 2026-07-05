#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
"$ROOT/scripts/build.sh" >/dev/null
cd "$ROOT/build"
ditto -c -k --sequesterRsrc --keepParent "Codex Reconnect Doctor.app" "Codex-Reconnect-Doctor-arm64.zip"
echo "$ROOT/build/Codex-Reconnect-Doctor-arm64.zip"

