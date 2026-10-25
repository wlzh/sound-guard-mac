#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
zsh scripts/check-docs.sh
mkdir -p dist
STAGING="$(mktemp -d "$PWD/dist/.soundguard-build.XXXXXX")"
trap 'rm -rf "$STAGING"' EXIT
APP="$STAGING/Sound Guard.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
swift build -c release --product SoundGuard --triple arm64-apple-macosx14.2
ARM="$(swift build -c release --triple arm64-apple-macosx14.2 --show-bin-path)"
swift build -c release --product SoundGuard --triple x86_64-apple-macosx14.2
INTEL="$(swift build -c release --triple x86_64-apple-macosx14.2 --show-bin-path)"
lipo -create "$ARM/SoundGuard" "$INTEL/SoundGuard" -output "$APP/Contents/MacOS/SoundGuard"
strip -S "$APP/Contents/MacOS/SoundGuard"
if grep -a -qE '/Users/|/home/' "$APP/Contents/MacOS/SoundGuard"; then
    echo 'Release binary contains a local user path' >&2
    exit 1
fi
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/BrandMark.svg Resources/AppIcon.svg "$APP/Contents/Resources/"
swift scripts/make-icon.swift "$STAGING/AppIcon.iconset"
iconutil -c icns "$STAGING/AppIcon.iconset" -o "$APP/Contents/Resources/AppIcon.icns"
cp LICENSE "$APP/Contents/Resources/LICENSE"
cp -R docs "$APP/Contents/Resources/"
codesign --force --sign - --identifier uk.869hr.SoundGuard "$APP"
codesign --verify --deep --strict "$APP"
plutil -lint "$APP/Contents/Info.plist"
lipo -info "$APP/Contents/MacOS/SoundGuard"
if [[ -e "$PWD/dist/Sound Guard.app" ]]; then
    mv "$PWD/dist/Sound Guard.app" "$STAGING/previous.app"
fi
if ! mv "$APP" "$PWD/dist/Sound Guard.app"; then
    [[ ! -e "$STAGING/previous.app" ]] || mv "$STAGING/previous.app" "$PWD/dist/Sound Guard.app"
    exit 1
fi
APP="$PWD/dist/Sound Guard.app"
echo "APP=$APP; SIGNING=AD_HOC; NOTARIZATION=NOT_DONE"
