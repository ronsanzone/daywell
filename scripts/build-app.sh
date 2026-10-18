#!/bin/bash
set -euo pipefail
ROOT="$(git rev-parse --show-toplevel)"
swift build --package-path "$ROOT" -c release --product Daywell
BIN="$(swift build --package-path "$ROOT" -c release --show-bin-path)"
APP="$ROOT/dist/Daywell.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/Fonts"
cp "$BIN/Daywell" "$APP/Contents/MacOS/Daywell"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
if [[ -n "${BUILD_NUMBER:-}" ]]; then
  plutil -replace CFBundleVersion -string "$BUILD_NUMBER" "$APP/Contents/Info.plist"
fi
# Maple Mono is SIL OFL 1.1; its license travels with the font files.
cp "$ROOT/Resources/Fonts/"*.ttf "$ROOT/Resources/Fonts/OFL.txt" "$APP/Contents/Resources/Fonts/"
codesign --force --sign - "$APP"
codesign --verify --strict "$APP"
printf '\nBuilt local development app: %s\n' "$APP"
