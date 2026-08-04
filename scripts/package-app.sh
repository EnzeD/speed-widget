#!/bin/zsh

set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
APP_DIR="$PROJECT_DIR/dist/SpeedWidget.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
ENTITLEMENTS="$PROJECT_DIR/Support/SpeedWidget.entitlements"

cd "$PROJECT_DIR"
swift build -c release

if [[ -L "$APP_DIR" ]]; then
    print -u2 "Refusing to replace a symlinked app bundle: $APP_DIR"
    exit 1
fi

rm -rf -- "$APP_DIR"
mkdir -p "$MACOS_DIR"
cp ".build/release/SpeedWidget" "$MACOS_DIR/SpeedWidget"
cp "Support/Info.plist" "$CONTENTS_DIR/Info.plist"
codesign --force --sign - --options runtime --entitlements "$ENTITLEMENTS" "$APP_DIR"
codesign --verify --deep --strict --verbose=2 "$APP_DIR"

print "App created: $APP_DIR"
