#!/bin/bash
set -euo pipefail

CONFIGURATION="${1:-debug}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$ROOT/.build/Kai Live.app"
CONTENTS="$APP_DIR/Contents"
MACOS="$CONTENTS/MacOS"

cd "$ROOT"
swift build -c "$CONFIGURATION"

rm -rf "$APP_DIR"
mkdir -p "$MACOS"
cp "$ROOT/.build/$CONFIGURATION/KaiLive" "$MACOS/KaiLive"
cp "$ROOT/Resources/Info.plist" "$CONTENTS/Info.plist"

codesign --force --sign - \
    --entitlements "$ROOT/Resources/KaiLive.entitlements" \
    "$APP_DIR"

echo "$APP_DIR"
