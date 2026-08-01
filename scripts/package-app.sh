#!/bin/zsh

set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
APP_DIR="$PROJECT_DIR/dist/SpeedWidget.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"

cd "$PROJECT_DIR"
swift build -c release
mkdir -p "$MACOS_DIR"
cp ".build/release/SpeedWidget" "$MACOS_DIR/SpeedWidget"
cp "Support/Info.plist" "$CONTENTS_DIR/Info.plist"
codesign --force --deep --sign - "$APP_DIR"

print "App created: $APP_DIR"
