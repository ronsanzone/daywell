#!/bin/bash
# Installs the newest main build from GitHub Releases into /Applications.
set -euo pipefail
REPO=ronsanzone/daywell
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
gh release download --repo "$REPO" --pattern 'Daywell-*.zip*' --dir "$TMP"
(cd "$TMP" && shasum -a 256 -c Daywell-*.zip.sha256)
ditto -x -k "$TMP"/Daywell-*.zip "$TMP"
osascript -e 'quit app id "app.daywell.mac"' 2>/dev/null || true
pkill -x Daywell 2>/dev/null || true
rm -rf /Applications/Daywell.app
ditto "$TMP/Daywell.app" /Applications/Daywell.app
xattr -dr com.apple.quarantine /Applications/Daywell.app 2>/dev/null || true
open /Applications/Daywell.app
printf 'Installed %s (build %s)\n' "$(ls "$TMP"/Daywell-*.zip | xargs basename)" \
  "$(defaults read /Applications/Daywell.app/Contents/Info CFBundleVersion)"
