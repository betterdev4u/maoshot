#!/usr/bin/env bash
# Build MaoShot.app (universal: Apple Silicon + Intel, no Rosetta needed).
#   ./build.sh            → build/MaoShot.app
#   ./build.sh install    → also copy to /Applications and launch
#   ./build.sh dist       → also zip it as build/MaoShot-<version>.zip for sharing
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release --arch arm64 --arch x86_64
BIN="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/MaoShot"

APP=build/MaoShot.app
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/MaoShot"
cp Resources/Info.plist "$APP/Contents/Info.plist"
# Cat app icon: generated from CatIcon.swift on first build (delete Resources/AppIcon.icns to regenerate).
if [[ ! -f Resources/AppIcon.icns ]]; then
  ICONSET="$(mktemp -d)/AppIcon.iconset"
  "$BIN" --make-iconset "$ICONSET"
  iconutil -c icns "$ICONSET" -o Resources/AppIcon.icns
fi
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# Signing: an Apple Development / Developer ID cert keeps Screen Recording permission across rebuilds.
# Without one we sign ad-hoc, and permission must be re-granted after every rebuild.
# (A self-signed cert was tried: macOS 27 signs with it but never matches the Screen Recording grant.)
SIGN_ID="${SIGN_ID:-$(security find-identity -v -p codesigning 2>/dev/null | awk -F'"' '/Apple Development|Developer ID Application/ {print $2; exit}')}"
codesign --force --options runtime --sign "${SIGN_ID:--}" "$APP"
echo "Built $APP (signed with: ${SIGN_ID:-ad-hoc})"

if [[ "${1:-}" == "install" ]]; then
  pkill -x MaoShot 2>/dev/null || true
  rm -rf /Applications/MaoShot.app
  cp -R "$APP" /Applications/
  # Keep exactly one registered copy so Screen Recording permission binds to /Applications/MaoShot.app.
  "$LSREGISTER" -u "$APP" 2>/dev/null || true
  rm -rf "$APP"
  open /Applications/MaoShot.app
  echo "Installed to /Applications/MaoShot.app"
fi

if [[ "${1:-}" == "dist" ]]; then
  VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Resources/Info.plist)"
  ZIP="build/MaoShot-$VERSION.zip"
  rm -f "$ZIP"
  ditto -c -k --keepParent "$APP" "$ZIP"
  # Don't leave a second MaoShot.app around: duplicate copies confuse the Screen Recording permission.
  "$LSREGISTER" -u "$APP" 2>/dev/null || true
  rm -rf "$APP"
  echo "Packaged $ZIP"
fi
