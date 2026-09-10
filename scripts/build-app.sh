#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
APP="$PWD/dist/Sound Guard.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
swift build -c release --product SoundGuard --triple arm64-apple-macosx14.2
ARM="$(swift build -c release --triple arm64-apple-macosx14.2 --show-bin-path)"
swift build -c release --product SoundGuard --triple x86_64-apple-macosx14.2
INTEL="$(swift build -c release --triple x86_64-apple-macosx14.2 --show-bin-path)"
lipo -create "$ARM/SoundGuard" "$INTEL/SoundGuard" -output "$APP/Contents/MacOS/SoundGuard"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/BrandMark.svg Resources/AppIcon.svg "$APP/Contents/Resources/"
swift scripts/make-icon.swift "$PWD/dist/AppIcon.iconset"
iconutil -c icns "$PWD/dist/AppIcon.iconset" -o "$APP/Contents/Resources/AppIcon.icns"
cp LICENSE "$APP/Contents/Resources/LICENSE"
cp -R docs "$APP/Contents/Resources/"
codesign --force --sign - --identifier uk.869hr.SoundGuard "$APP"
codesign --verify --deep --strict "$APP"
plutil -lint "$APP/Contents/Info.plist"
lipo -info "$APP/Contents/MacOS/SoundGuard"
echo "APP=$APP; SIGNING=AD_HOC; NOTARIZATION=NOT_DONE"
