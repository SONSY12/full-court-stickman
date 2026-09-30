#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
APP="build/Full Court Stickman.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" dist
swiftc work/CourtDemo.swift work/AutoUpdater.swift work/CharacterMotion.swift work/BallPhysics.swift -o build/FullCourt-arm64 -target arm64-apple-macos13.0 -module-cache-path /private/tmp/fullcourt-swift-cache
swiftc work/CourtDemo.swift work/AutoUpdater.swift work/CharacterMotion.swift work/BallPhysics.swift -o build/FullCourt-x86_64 -target x86_64-apple-macos13.0 -module-cache-path /private/tmp/fullcourt-swift-cache
lipo -create build/FullCourt-arm64 build/FullCourt-x86_64 -output "$APP/Contents/MacOS/FullCourt"
cp work/Info.plist "$APP/Contents/Info.plist"
cp outputs/basketball-court-v1.png "$APP/Contents/Resources/"
for asset in character-idle-sheet-v1.png character-walk-sheet-v1.png character-standing-shot-sheet-v2.png character-jump-sheet-v2.png character-jump-shot-sheet-v1.png character-jump-block-sheet-v1.png character-dunk-sheet-v1.png character-defense-sheet-v1.png; do
  cp "outputs/$asset" "$APP/Contents/Resources/"
done
mkdir -p "$APP/Contents/Resources/body-v2"
for asset in character-idle-sheet-v1.png character-walk-sheet-v1.png character-standing-shot-sheet-v2.png character-jump-sheet-v2.png character-jump-shot-sheet-v1.png character-jump-block-sheet-v1.png character-dunk-sheet-v1.png character-defense-sheet-v1.png; do
  cp "outputs/body-v2/$asset" "$APP/Contents/Resources/body-v2/"
done
for face in front left right back; do
  cp "outputs/head-$face-v2.png" "$APP/Contents/Resources/"
done
codesign --force --deep --sign - "$APP"
ditto -c -k --sequesterRsrc --keepParent "$APP" dist/Full-Court-Stickman.zip
shasum -a 256 dist/Full-Court-Stickman.zip
