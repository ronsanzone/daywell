#!/bin/bash
set -euo pipefail
ROOT="$(git rev-parse --show-toplevel)"
swift build --package-path "$ROOT" -c release --product Daywell
BIN="$(swift build --package-path "$ROOT" -c release --show-bin-path)"
APP="$ROOT/dist/Daywell.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/Daywell" "$APP/Contents/MacOS/Daywell"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"
codesign --verify --strict "$APP"
printf '\nBuilt local development app: %s\n' "$APP"
