#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION="$(tr -d '[:space:]' < VERSION)"
ARCHIVE="SoundGuard-v$VERSION-macos-universal.zip"
test ! -e "dist/$ARCHIVE" || { echo 'Refusing to overwrite an existing release archive' >&2; exit 1; }
zsh scripts/test-all.sh
zsh scripts/build-app.sh
ditto -c -k --sequesterRsrc --keepParent "dist/Sound Guard.app" "dist/$ARCHIVE"
unzip -tq "dist/$ARCHIVE"
cd dist
shasum -a 256 "$ARCHIVE" > SHA256.txt
cp SHA256.txt "$ARCHIVE.sha256"
shasum -a 256 -c SHA256.txt
