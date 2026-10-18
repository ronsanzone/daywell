#!/bin/bash
# Authorized live Reminders acceptance. Writes only to disposable lists it creates,
# then removes them. Bundles DaywellDev so macOS asks for Reminders access on its
# behalf rather than the terminal's, and prints the results here.
set -euo pipefail
ROOT="$(git rev-parse --show-toplevel)"
swift build --package-path "$ROOT" -c release --product DaywellDev
BIN="$(swift build --package-path "$ROOT" -c release --show-bin-path)"
APP="$ROOT/dist/DaywellDev.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN/DaywellDev" "$APP/Contents/MacOS/DaywellDev"
sed -e 's/app.daywell.mac/app.daywell.dev/' -e 's#<string>Daywell</string>#<string>DaywellDev</string>#g' \
  "$ROOT/Resources/Info.plist" > "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"
LOG="$(mktemp -t daywell-live-check)"
open -W --stdout "$LOG" --stderr "$LOG" "$APP" --args --live-check
cat "$LOG"
